# socatVPN
Secure yet simple VPN tunnel using socat and openssl (SOCKS5 over TLS)

1. Download `socatvpn.sh` and make it executable:
```
wget https://raw.githubusercontent.com/fffaraz/socatvpn/main/socatvpn.sh
chmod +x socatvpn.sh

./socatvpn.sh install
```

2. Generate a client certificate on the client:
```
./socatvpn.sh cert-client
```

3. Upload `./cert/client.crt` to the server. Alternatively, you can run `./socatvpn.sh cert` on the server to generate a certificate for both the server and the client. Then, copy `./cert/client.crt` and `./cert/client.key` to the client.

4. Generate a server certificate on the server:
```
./socatvpn.sh cert-server
```

5. Download `./cert/server.crt` on the client (optional).

6. Run the server:
```
./socatvpn.sh server 443
```

7. Run the client:
```
./socatvpn.sh client SERVER_IP:443
```
