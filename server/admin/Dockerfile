FROM golang:1.21-alpine AS builder
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o /app/admin .

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/admin /app/admin
ENTRYPOINT ["/app/admin"]
