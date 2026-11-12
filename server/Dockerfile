FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /dingdong-server .

FROM alpine:3.20
COPY --from=build /dingdong-server /usr/local/bin/dingdong-server
VOLUME /data
EXPOSE 8787
ENTRYPOINT ["dingdong-server", "-addr", "0.0.0.0:8787", "-data", "/data"]
