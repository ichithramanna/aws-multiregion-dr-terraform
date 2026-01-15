from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return "Backend running in Docker on AWS"

@app.route("/health")
def health():
    return "OK"
