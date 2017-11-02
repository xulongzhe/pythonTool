#!/usr/bin/python  
#coding=utf-8 

import socket
import smtplib
import logging
import sys
from BaseHTTPServer import BaseHTTPRequestHandler
from StringIO import StringIO
from email.mime.text import MIMEText  
from email.header import Header 

reload(sys)
sys.setdefaultencoding('utf-8')

recipients=["xiajibayong@sohu.com"]
mailserver = 'smtp.sohu.com'
user = 'xiajibayong@sohu.com'  
passwd = '88909090'

logging.basicConfig(level=logging.DEBUG,
                format='%(asctime)s [line:%(lineno)d] %(levelname)s %(message)s',
                datefmt='%Y-%m-%d %H:%M:%S',
                filename='emailproxy.log',
                filemode='a')

class HTTPRequest(BaseHTTPRequestHandler):
    def __init__(self, request_text):
        self.rfile = StringIO(request_text)
        self.raw_requestline = self.rfile.readline()
        self.error_code = self.error_message = None
        self.parse_request()
 
    def send_error(self, code, message):
        self.error_code = code
        self.error_message = message
		
def send(content):
	msg = MIMEText(content,'plain','utf-8')
	msg['Subject'] = Header("异常告警", 'utf-8')
	server = smtplib.SMTP(mailserver,25)
	server.login(user,passwd)
	server.sendmail(user, recipients, msg.as_string())
	server.quit()
 
HOST, PORT = '21.60.100.83', 8888
 
listen_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
listen_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listen_socket.bind((HOST, PORT))
listen_socket.listen(1)
logging.info('Serving HTTP on port %s ...' % PORT)
while True:
	client_connection, client_address = listen_socket.accept()
	try:
		request = client_connection.recv(1024)
		rs=unicode(request, "utf-8")
		logging.info(rs)
		send(rs)
		http_response = """
HTTP/1.1 200 OK
"""
	except BaseException as e:
		logging.exception(e)
		http_response = """
http/1.1 500 server error
"""
	finally:
		client_connection.sendall(http_response)
		client_connection.close()
