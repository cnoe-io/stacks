# Use the official Golang image as the base image
FROM golang:1.22 as builder

# Set the Current Working Directory inside the container
WORKDIR /app

# Copy go mod files if they exist
COPY go.mod ./

# Download all dependencies. Dependencies will be cached if the go.mod and go.sum files are not changed
RUN go mod download

# Copy the source code into the container
COPY main.go .

# Build the Go app
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o myapp .

# Command to run the executable
CMD ["./myapp"]

# # Start a new stage from scratch
# FROM alpine:latest  

# WORKDIR /root/

# # Copy the Pre-built binary file from the previous stage
# COPY --from=builder /app/myapp .

# # Command to run the executable
# CMD ["./myapp"]