FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd cmd
COPY internal internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/farash-api ./cmd/api

FROM alpine:3.21
RUN addgroup -S farash && adduser -S -G farash -u 10001 farash
COPY --from=build /out/farash-api /usr/local/bin/farash-api
USER farash
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/farash-api"]
