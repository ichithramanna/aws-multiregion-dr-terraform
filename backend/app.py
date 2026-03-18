from flask import Flask, jsonify
from flask_cors import CORS  
import pymysql, os, time, threading, queue, boto3, json
import urllib.request

app = Flask(__name__)
CORS(app, origins=["https://app.ichith.it"])  

READ_ONLY_ERRNO   = 1836
SQS_QUEUE_URL     = os.environ.get("SQS_QUEUE_URL", "")
GLOBAL_CLUSTER_ID = os.environ.get("GLOBAL_CLUSTER_ID", "")
TARGET_CLUSTER_ARN= os.environ.get("TARGET_CLUSTER_ARN", "")
AWS_REGION        = os.environ.get("AWS_REGION", "us-east-1")

sqs = boto3.client("sqs", region_name=AWS_REGION) if SQS_QUEUE_URL else None

def get_db():
    return pymysql.connect(
        host=os.environ["DB_HOST"], user="admin",
        password=os.environ["DB_PASSWORD"], database="appdb", connect_timeout=5
    )

def get_region():
    return urllib.request.urlopen(
        "http://169.254.169.254/latest/meta-data/placement/region", timeout=2
    ).read().decode()

# ── Background Thread 1: Aurora Promotion ────────────────────────
# Runs once on startup. If this is the DR region and Aurora is not
# yet writer, calls describe_global_clusters to check — Lambda
# handles actual promotion, but this thread acts as a safety net.
def promote_aurora_if_needed():
    if not TARGET_CLUSTER_ARN:
        return  # primary region — skip
    time.sleep(15)  # wait for network after EC2 boot
    try:
        client = boto3.client("rds", region_name="us-east-1")
        clusters = client.describe_global_clusters(
            GlobalClusterIdentifier=GLOBAL_CLUSTER_ID
        )["GlobalClusters"]
        if not clusters:
            return
        writers = [m for m in clusters[0]["GlobalClusterMembers"] if m["IsWriter"]]
        if writers and "us-west-2" in writers[0]["DBClusterArn"]:
            print("[INFO] DR already writer")
            return
        print("[INFO] Promotion check: Lambda should handle this. Monitoring...")
    except Exception as e:
        print(f"[WARN] Promotion check failed: {e}")

# ── Background Thread 2: SQS Drain Worker ────────────────────────
# Infinite loop — polls SQS every 5s.
# When Aurora is promoted, drain worker flushes all queued writes.
# Only deletes SQS message AFTER successful DB commit — no data loss.
def sqs_drain_worker():
    if not sqs or not SQS_QUEUE_URL:
        return  # SQS not configured — primary region
    while True:
        try:
            resp = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=5      # long polling — efficient, not hammering SQS
            )
            for msg in resp.get("Messages", []):
                data = json.loads(msg["Body"])
                try:
                    conn = get_db()
                    cursor = conn.cursor()
                    cursor.execute("INSERT INTO visits (region) VALUES (%s)", (data["region"],))
                    conn.commit()
                    conn.close()
                    sqs.delete_message(
                        QueueUrl=SQS_QUEUE_URL,
                        ReceiptHandle=msg["ReceiptHandle"]
                    )
                    print(f"[DRAIN] Flushed queued write for region: {data['region']}")
                except pymysql.err.InternalError as e:
                    if e.args[0] == READ_ONLY_ERRNO:
                        pass  # Aurora not promoted yet — leave in queue, re-delivered after visibility timeout
                    else:
                        print(f"[DRAIN ERROR] {e}")
        except Exception as e:
            print(f"[DRAIN POLL ERROR] {e}")
            time.sleep(5)

# Start background threads on app boot
threading.Thread(target=promote_aurora_if_needed, daemon=True).start()
threading.Thread(target=sqs_drain_worker, daemon=True).start()

@app.route("/")
def home():
    return "Backend running in Docker on AWS"

@app.route("/health")
def health():
    return "OK"

@app.route("/region")
def region():
    try:
        return jsonify({"serving_from": get_region()})
    except Exception as e:
        return jsonify({"serving_from": "unknown", "error": str(e)}), 500

@app.route("/db-test")
def db_test():
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("SELECT 'DB Connected!' as msg")
        result = cursor.fetchone()
        conn.close()
        return jsonify({"status": "success", "message": result[0]})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/write")
def write():
    conn = None
    try:
        r = get_region()
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS visits (
                id INT AUTO_INCREMENT PRIMARY KEY,
                region VARCHAR(50),
                ts TIMESTAMP DEFAULT NOW()
            )
        """)
        cursor.execute("INSERT INTO visits (region) VALUES (%s)", (r,))
        conn.commit()
        conn.close()
        return jsonify({"status": "success", "message": f"Visit recorded from {r}", "queued": False})

    except (pymysql.err.InternalError, pymysql.err.OperationalError) as e:
        if conn:
            try: conn.close()
            except: pass
        
        # Debug logging to see what errno we're actually getting
        print(f"[DEBUG] InternalError: args={e.args}, errno={e.args[0] if e.args else 'none'}")
        
        # Check if it's read-only error (1836)
        if len(e.args) > 0 and e.args[0] == READ_ONLY_ERRNO and sqs and SQS_QUEUE_URL:
            # Aurora not yet promoted — buffer in SQS
            sqs.send_message(
                QueueUrl=SQS_QUEUE_URL,
                MessageBody=json.dumps({"region": get_region()})
            )
            return jsonify({
                "status": "success",
                "message": "Write queued — will persist once DR Aurora is promoted",
                "queued": True
            })
        
        return jsonify({"status": "error", "message": str(e)}), 500

    except Exception as e:
        if conn:
            try: conn.close()
            except: pass
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/read")
def read():
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("SELECT region, COUNT(*) as count FROM visits GROUP BY region")
        rows = cursor.fetchall()
        conn.close()
        return jsonify({
            "serving_from": get_region(),
            "status": "success",
            "visits": [{"region": r[0], "count": r[1]} for r in rows]
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500
    
@app.route("/read-all")
def read_all():
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("SELECT id, region, ts FROM visits ORDER BY ts DESC")
        rows = cursor.fetchall()
        conn.close()
        return jsonify({
            "serving_from": get_region(),
            "total": len(rows),
            "visits": [{"id": r[0], "region": r[1], "ts": str(r[2])} for r in rows]
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)




