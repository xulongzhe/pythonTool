#! /usr/bin/python
# -*- coding: utf-8 -*-
import sys,commands,threading
args = sys.argv
if len(args) == 1:
    print("Execute several commands concurrently and output in order")
    print("Usage: " + args[0] + " command1 command2 command3 ...")
    exit()

index = 1
con = threading.Condition()

def execute(i, cmd):
    global index
    (status, output) = commands.getstatusoutput(cmd)
    con.acquire()
    while index != i:
        con.wait()
    index += 1
    con.notify_all()
    if status == 0:
        print output
    else:
        print("ERROR: " + cmd + "\n" + output)
    con.release()

for i in range(1, len(args)):
    t =threading.Thread(target=execute, args=(i, args[i],))
    t.start()

