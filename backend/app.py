from flask import Flask, jsonify
import pymysql
import os
import urllib.request

app = Flask(__name__)

def get_db():
    return pymysql.connect(
        host=os.environ["DB_HOST"],
        user="admin",
        password=os.environ["DB_PASSWORD"],
        database="appdb",
        connect_timeout=5
    )

def get_region():
    return urllib.request.urlopen(
        "http://169.254.169.254/latest/meta-data/placement/region",
        timeout=2
    ).read().decode()

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
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS visits (
                id INT AUTO_INCREMENT PRIMARY KEY,
                region VARCHAR(50),
                ts TIMESTAMP DEFAULT NOW()
            )
        """)
        r = get_region()
        cursor.execute("INSERT INTO visits (region) VALUES (%s)", (r,))
        conn.commit()
        conn.close()
        return jsonify({
            "status": "success",
            "message": f"Visit recorded from {r}"
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/read")
def read():
    try:
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT region, COUNT(*) as count FROM visits GROUP BY region"
        )
        rows = cursor.fetchall()
        conn.close()
        return jsonify({
            "serving_from": get_region(),
            "status": "success",
            "visits": [{"region": r[0], "count": r[1]} for r in rows]
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)