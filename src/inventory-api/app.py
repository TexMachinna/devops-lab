from flask import Flask, jsonify

app = Flask(__name__)

ITEMS = [
    {"sku": "BOLT-M8", "name": "M8 bolt", "stock": 1200},
    {"sku": "NUT-M8", "name": "M8 nut", "stock": 950},
]

@app.get("/health")
def health():
    return jsonify(status="ok")

@app.get("/api/items")
def list_items():
    return jsonify(ITEMS)# drill 8.4
