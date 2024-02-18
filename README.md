# socatVPN
Secure yet simple VPN tunnel using socat and openssl (SOCKS5 over TLS)

1. Download `socatvpn.sh` and make it executable on both server and client:
```
wget https://raw.githubusercontent.com/fffaraz/socatvpn/main/socatvpn.sh
chmod +x socatvpn.sh
./socatvpn.sh install
```

2. Generate a private key and certificate for both the server and client on the server:
```
./socatvpn.sh cert
```

3. Copy `./cert/client.crt` and `./cert/client.key` to the client.

4. Run the server:
```
./socatvpn.sh server 443
```

5. Run the client:
```
./socatvpn.sh client SERVER_IP:443
```
