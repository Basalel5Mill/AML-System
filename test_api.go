package main

import (
	"cloud.google.com/go/bigquery"
	"fmt"
	"reflect"
)

func main() {
	// Create a dummy loader to inspect the API
	var loader *bigquery.Loader
	
	// Print the type and fields
	t := reflect.TypeOf(loader).Elem()
	fmt.Printf("Loader type: %s\n", t.Name())
	
	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		fmt.Printf("Field %d: %s (type: %s)\n", i, field.Name, field.Type)
	}
}