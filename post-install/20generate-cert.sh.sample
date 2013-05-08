# Generate SSL cert for Trac installation
# Feel free to replace this with your own certificates
# Author: Tuomo Tanskanen <tumi@tumi.fi>

if [ ! -z "$SSL_CERT_RESPONSES" ]; then
  cd $TRAC_INSTALL
  openssl genrsa -out ca.key 2048
  echo -e $SSL_CERT_RESPONSES | openssl req -new -key ca.key -out ca.csr
  openssl x509 -req -days 365 -in ca.csr -signkey ca.key -out ca.crt
  chmod 600 ca.*
  cp ca.crt /etc/ssl/certs/
  cp ca.key /etc/ssl/private/
  cp ca.csr /etc/ssl/private/
fi

