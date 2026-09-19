
FROM ghcr.io/cirruslabs/flutter:3.47.0
USER root
COPY .devcontainer/container-main.sh /usr/local/bin/pandora-container-main
RUN chmod 0755 /usr/local/bin/pandora-container-main
CMD ["/usr/local/bin/pandora-container-main"]
