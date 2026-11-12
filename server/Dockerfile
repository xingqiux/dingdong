FROM golang:1.23-alpine AS build
ARG VERSION=dev
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /dingdong-server .

FROM alpine:3.20
COPY --from=build /dingdong-server /usr/local/bin/dingdong-server
VOLUME /data
EXPOSE 8787
ENTRYPOINT ["dingdong-server", "-addr", "0.0.0.0:8787", "-data", "/data"]
