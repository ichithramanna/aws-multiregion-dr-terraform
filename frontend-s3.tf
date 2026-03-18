#creating S3 bucket
resource "aws_s3_bucket" "frontend" {
  bucket = "my-frontend-bucket-tta-10-25"
}

#Block all public access for cloudfront-only access
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#Upload a static HTML file
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  content_type = "text/html"

  content = <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Three-Tier AWS DR Demo</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 800px; margin: 60px auto; padding: 0 20px; background: #f5f5f5; }
    h1 { color: #232f3e; }
    .card { background: white; border-radius: 8px; padding: 20px; margin: 16px 0; box-shadow: 0 2px 6px rgba(0,0,0,0.1); }
    .label { font-size: 12px; color: #888; text-transform: uppercase; margin-bottom: 4px; }
    .value { font-size: 20px; font-weight: bold; color: #232f3e; }
    button { background: #232f3e; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; margin: 6px 4px; font-size: 14px; }
    button:hover { background: #ff9900; }
    table { width: 100%; border-collapse: collapse; margin-top: 10px; }
    th, td { text-align: left; padding: 10px; border-bottom: 1px solid #eee; }
    th { color: #888; font-size: 12px; text-transform: uppercase; }
    #status { font-size: 13px; color: #888; margin-top: 8px; }
  </style>
</head>
<body>
  <h1>🌐 Three-Tier AWS — Multi-Region DR Demo</h1>
  <p style="color:#555">Frontend: <strong>S3 + CloudFront (us-east-1)</strong> &nbsp;|&nbsp; Backend: <strong>EC2 + ALB via Global Accelerator</strong> &nbsp;|&nbsp; DB: <strong>Aurora Global Database</strong></p>

  <div class="card">
    <div class="label">Backend currently serving from</div>
    <div class="value" id="region">Loading...</div>
    <div id="status"></div>
  </div>

  <div class="card">
    <button onclick="writeVisit()">✍️ Write Visit to Aurora</button>
    <button onclick="loadVisits()">📖 Read All Visits</button>
    <button onclick="checkHealth()">❤️ Health Check</button>
    <div id="write-result" style="margin-top:12px; font-size:14px;"></div>
  </div>

  <div class="card">
    <div class="label">Visit Records (from Aurora)</div>
    <table>
      <thead><tr><th>Region</th><th>Visit Count</th></tr></thead>
      <tbody id="visits-table"><tr><td colspan="2" style="color:#aaa">Click "Read All Visits" to load</td></tr></tbody>
    </table>
  </div>

  <script>
    const API = "https://api.ichith.it";

    async function getRegion() {
      try {
        const res = await fetch(`$${API}/region`);
        const data = await res.json();
        document.getElementById("region").textContent = data.serving_from;
        document.getElementById("status").textContent = "✅ Backend reachable";
        document.getElementById("status").style.color = "#2ecc71";
      } catch (e) {
        document.getElementById("region").textContent = "Unreachable";
        document.getElementById("status").textContent = "❌ Backend down — DR may be activating";
        document.getElementById("status").style.color = "#e74c3c";
      }
    }

    async function writeVisit() {
      const el = document.getElementById("write-result");
      el.textContent = "Writing...";
      try {
        const res = await fetch(`$${API}/write`);
        const data = await res.json();
        el.textContent = data.queued
          ? `⏳ Queued in SQS — Aurora promoting. Will persist once DR is writer.`
          : `✅ $${data.message}`;
        el.style.color = data.queued ? "#e67e22" : "#2ecc71";
        loadVisits();
      } catch (e) {
        el.textContent = "❌ Write failed: " + e.message;
        el.style.color = "#e74c3c";
      }
    }

    async function loadVisits() {
      try {
        const res = await fetch(`$${API}/read`);
        const data = await res.json();
        const tbody = document.getElementById("visits-table");
        if (!data.visits || data.visits.length === 0) {
          tbody.innerHTML = `<tr><td colspan="2" style="color:#aaa">No visits yet</td></tr>`;
          return;
        }
        tbody.innerHTML = data.visits.map(v =>
          `<tr><td>$${v.region}</td><td><strong>$${v.count}</strong></td></tr>`
        ).join("");
      } catch (e) {
        document.getElementById("visits-table").innerHTML =
          `<tr><td colspan="2" style="color:#e74c3c">Failed to load</td></tr>`;
      }
    }

    async function checkHealth() {
      const el = document.getElementById("write-result");
      try {
        const res = await fetch(`$${API}/health`);
        const text = await res.text();
        el.textContent = `❤️ Health: $${text}`;
        el.style.color = "#2ecc71";
      } catch (e) {
        el.textContent = "❌ Health check failed";
        el.style.color = "#e74c3c";
      }
    }

    getRegion();
    setInterval(getRegion, 10000);
  </script>
</body>
</html>
EOF
}

#adding policy for Only this CloudFront distribution read
resource "aws_s3_bucket_policy" "frontend" {

  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
        }
      }
    }]
  })
}
