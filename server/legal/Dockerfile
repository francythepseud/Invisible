FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o legal .

FROM scratch
COPY --from=builder /app/legal /legal
EXPOSE 8083
ENTRYPOINT ["/legal"]
