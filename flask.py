#
from flask import Flask
from flask import request
import json, sqlite3

app = Flask(__name__)


@app.route('/register', methods=['POST'])
def register():
    obj = request.json
    print(obj)
    id = obj['id']
    ip = obj['ip']
    os = obj['os']
    cpu = obj['cpu']
    mem = obj['mem']

    def insert_or_update(c):
        try:
            c.execute('insert into server (id,ip,os,cpu,mem) VALUES (?,?,?,?,?)', (id, ip, os, cpu, mem))
        except Exception as e:
            print(e)
            c.execute('update server set ip=?,os=?,cpu=?,mem=? WHERE id=?', (ip, os, cpu, mem, id))

    sql(insert_or_update)
    return json.dumps({'status': 'ok'})


@app.route('/report', methods=['POST'])
def report():
    obj = request.json
    id = obj['id']
    product = obj['product']
    sql(lambda c: c.execute('update server set product=? WHERE id=?', (product, id)))
    return json.dumps({'status': 'ok'})


@app.route('/assign', methods=['POST'])
def assign():
    obj = request.json
    ids = obj['id']
    user = obj['user']
    purpose = obj['purpose']
    sql(lambda c: c.execute('update server set user=?,purpose=? WHERE id=?', (user, purpose, id)))
    return json.dumps({'status': 'ok'})


def sql(execute):
    conn = sqlite3.connect('C:/Users/x02454/Desktop/server')
    cursor = conn.cursor()
    execute(cursor)
    cursor.close()
    conn.commit()
    conn.close()


if __name__ == '__main__':
    app.debug = True
    app.run(host='0.0.0.0')
