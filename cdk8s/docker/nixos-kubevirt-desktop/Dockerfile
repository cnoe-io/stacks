FROM nginx:alpine

# Copy qcow2 file to nginx html directory
# The qcow2 file should be built using nixos-generate and placed in the same directory as this Dockerfile
COPY nixos.qcow2 /usr/share/nginx/html/nixos.qcow2

# Configure nginx to allow large file downloads and enable directory listing
RUN echo 'server { \
    listen 80; \
    server_name localhost; \
    client_max_body_size 0; \
    location / { \
        root /usr/share/nginx/html; \
        autoindex on; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
