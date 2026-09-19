FROM mcr.microsoft.com/devcontainers/universal:2-linux
USER root
COPY .devcontainer/container-main.sh /usr/local/bin/pandora-container-main
RUN chmod 0755 /usr/local/bin/pandora-container-main
CMD ["/usr/local/bin/pandora-container-main"]
