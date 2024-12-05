FROM nginx:alpine

# Install dependencies
RUN apk add -u --no-cache imagemagick bash gzip tar

WORKDIR /opt/gst-web
COPY . .
RUN INSTALL_DIR="/usr/share/nginx/html" ./install.sh

# Create release tarball
RUN cp -R /usr/share/nginx/html /tmp/gst-web && \
  cd /tmp && tar -czvf /opt/gst-web.tar.gz gst-web && \
  rm -rf /tmp/gst-web

ENV GST_WEB_PORT=80
ENV PATH_PREFIX="/"

COPY entrypoint.sh /entrypoint.sh
CMD ["sh", "-c", "/entrypoint.sh"]
