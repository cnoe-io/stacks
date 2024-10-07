package main

import (
	"net/http"
	"encoding/json"
	"log"
	"os"
)

type Response struct {
	Message string `json:"message"`
}

// ping handler
func pingHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	hostname, err := os.Hostname()
	if err != nil {
		log.Println("Error : %v", err)
		return
	}

	response := Response{Message: "pong from server : "+hostname}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func main(){
	http.HandleFunc("/ping", pingHandler)
	log.Println("Server started on 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

