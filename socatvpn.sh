#!/bin/bash
#
# Socat VPN: secure yet simple VPN tunnel using socat and openssl (v1.0.0)
# Copyright (c) 2024 Faraz Fallahi <fffaraz@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

set -euo pipefail

function print_usage() {
	echo "Usage: $0 [command]"
	echo "Commands:"
	echo "  install                  Install required packages."
	echo "  cert-server              Generate server certificate. Overwrite existing."
	echo "  cert-client              Generate client certificate. Overwrite existing."
	echo "  cert                     Generate server and client certificates. Keep existing."
	echo "  key                      Print server public key and client public/private key."
	echo "  server [port]            Run socat VPN server. Requires client certificate."
	echo "  client [ip:port] [pkey]  Run socat VPN client. Requires client private key."
}

function print_public_key() {
	openssl x509 -in "$1" -noout -pubkey | openssl pkey -pubin -outform DER | tail -c+13 | xxd -p -c 256
}

function print_private_key() {
	openssl pkey -in "$1" -outform DER | tail -c+13 | xxd -p -c 256
}

function print_both_public_keys() {
	if [ -f ./cert/server.crt ]; then
		echo -n "Server public key: "
		print_public_key ./cert/server.crt
	else
		echo "Server public key not found,"
	fi
	if [ -f ./cert/client.crt ]; then
		echo -n "Client public key: "
		print_public_key ./cert/client.crt
	else
		echo "Client public key not found,"
	fi
}

function command_exists {
	command -v "$@" &>/dev/null
}

function gen_server_cert() {
	IPV4=$(dig +short myip.opendns.com @208.67.222.222 a) || IPV4=""
	echo "Server IPv4 address: $IPV4"

	IPV6=$(dig +short myip.opendns.com @2620:0:ccc::2 aaaa) || IPV6=""
	echo "Server IPv6 address: $IPV6"

	ALT_NAMES="subjectAltName=DNS:*.nip.io,"
	if [ -n "$IPV4" ]; then
		ALT_NAMES="${ALT_NAMES}IP:${IPV4},"
	fi
	if [ -n "$IPV6" ]; then
		ALT_NAMES="${ALT_NAMES}IP:${IPV6},"
	fi
	ALT_NAMES="${ALT_NAMES%,}" # remove last comma

	mkdir -p ./cert
	rm -f ./cert/server.key
	rm -f ./cert/server.crt

	openssl genpkey -algorithm ed25519 -out ./cert/server.key
	openssl req -new -x509 -sha256 -key ./cert/server.key -out ./cert/server.crt -days 3650 -subj '/CN=*.nip.io' -addext "$ALT_NAMES"

	echo -n "Server public key: "
	print_public_key ./cert/server.crt
}

function gen_client_cert() {
	mkdir -p ./cert
	rm -f ./cert/client.key
	rm -f ./cert/client.crt

	openssl genpkey -algorithm ed25519 -out ./cert/client.key
	openssl req -new -x509 -sha256 -key ./cert/client.key -out ./cert/client.crt -days 3650 -subj '/'

	echo -n "Client public key: "
	print_public_key ./cert/client.crt
}

if [ $# -lt 1 ]; then
	print_usage
	exit 1
fi

if [ "$1" == "install" ]; then
	sudo apt-get update
	sudo apt-get install -yq curl dnsutils openssl socat vnstat xxd
	exit 0
fi

if [ "$1" == "cert-server" ]; then
	gen_server_cert
	exit 0
fi

if [ "$1" == "cert-client" ]; then
	gen_client_cert
	exit 0
fi

if [ "$1" == "cert" ]; then
	if [ ! -f ./cert/server.key ]; then
		gen_server_cert
	else
		echo -n "Server public key: "
		print_public_key ./cert/server.crt
	fi

	if [ ! -f ./cert/client.key ]; then
		gen_client_cert
	else
		echo -n "Client public key: "
		print_public_key ./cert/client.crt
	fi
	echo -n "Client private key: "
	print_private_key ./cert/client.key

	exit 0
fi

if [ "$1" == "key" ]; then
	print_both_public_keys
	if [ ! -f ./cert/client.key ]; then
		echo "Client private key not found."
		exit 1
	fi
	echo -n "Client private key: "
	print_private_key ./cert/client.key
	exit 0
fi

if [ "$1" == "server" ]; then
	if [ $# -lt 2 ]; then
		echo "Usage: $0 server [port]"
		exit 1
	fi
	if ! command_exists docker; then
		curl -fsSL https://get.docker.com/ | sudo sh
	fi
	if [ ! -f ./cert/client.crt ]; then
		echo "Client certificate not found."
		exit 1
	fi
	if [ ! -f ./cert/server.key ]; then
		gen_server_cert
	fi
	if [ ! -f ./cert/server.crt ]; then
		echo "Server certificate not found."
		exit 1
	fi
	PORT="$2"

	docker rm -f ghost 1>/dev/null 2>&1 || true
	docker run --detach --rm \
		--name ghost \
		--network host \
		ginuerzh/gost:2.11.5 \
		"-L=127.0.0.1:3128?whitelist=tcp:*:22,80,443,8080,8443,5228&dns=1.1.1.2" \
		1>/dev/null 2>&1

	killall socat 2>/dev/null || true
	socat -d \
		OPENSSL-LISTEN:${PORT},bind=0.0.0.0,fork,reuseaddr,verify=1,cert=./cert/server.crt,key=./cert/server.key,cafile=./cert/client.crt \
		TCP4:127.0.0.1:3128 || true

	docker rm -f ghost 1>/dev/null 2>&1 || true
	exit 0
fi

if [ "$1" == "client" ]; then
	if [ $# -lt 2 ]; then
		echo "Usage: $0 client [ip:port] [privatekey]"
		exit 1
	fi
	if [ ! -f ./cert/client.crt ] || [ ! -f ./cert/client.key ]; then
		if [ $# -lt 3 ]; then
			echo "Client certificate or private key not found."
			echo "Usage: $0 client [ip:port] [privatekey]"
			exit 1
		fi
		mkdir -p ./cert
		rm -f ./cert/client.crt
		rm -f ./cert/client.key
		echo "$3" | xxd -r -p | openssl pkey -inform DER -outform PEM -out ./cert/client.key
		openssl req -new -x509 -sha256 -key ./cert/client.key -out ./cert/client.crt -days 3650 -subj '/'
	fi
	SERVER_ADDR="$2"
	COMMON_NAME="${SERVER_ADDR%%:*}" # remove port number
	if [ ! -f ./cert/server.crt ]; then
		openssl s_client -connect ${SERVER_ADDR} -tls1_2 -showcerts </dev/null 2>/dev/null | openssl x509 -out ./cert/server.crt 2>/dev/null || true
		if [ ! -f ./cert/server.crt ]; then
			echo "Error: Failed to download server certificate."
			exit 1
		fi
	fi
	print_both_public_keys
	echo ""

	if [[ "$(uname)" != "Darwin" ]]; then
		IPV4=$(
			curl -sS \
				--proxytunnel \
				--proxy https://${SERVER_ADDR} \
				--proxy-cacert ./cert/server.crt \
				--proxy-cert ./cert/client.crt \
				--proxy-key ./cert/client.key \
				"http://ipv4.icanhazip.com"
		) || IPV4=""
		if [ -n "$IPV4" ]; then
			echo "IPv4 address: $IPV4"
		fi
		IPV6=$(
			curl -sS \
				--proxytunnel \
				--proxy https://${SERVER_ADDR} \
				--proxy-cacert ./cert/server.crt \
				--proxy-cert ./cert/client.crt \
				--proxy-key ./cert/client.key \
				"http://ipv6.icanhazip.com"
		) || IPV6=""
		if [ -n "$IPV6" ]; then
			echo "IPv6 address: $IPV6"
		fi

		echo ""
	fi

	echo "Listening on port 1080 for HTTP/SOCKS5 proxy connections..."
	echo ""
	socat -d \
		TCP4-LISTEN:1080,bind=127.0.0.1,fork,reuseaddr \
		OPENSSL-CONNECT:${SERVER_ADDR},commonname=${COMMON_NAME},verify=1,cert=./cert/client.crt,key=./cert/client.key,cafile=./cert/server.crt

	exit 0
fi

echo "Unknown command: $1"
print_usage
exit 1
