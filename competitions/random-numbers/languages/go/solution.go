package main

import (
	"bufio"
	"fmt"
	"math/rand"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	w := bufio.NewWriter(os.Stdout)
	for i := 0; i < n; i++ {
		fmt.Fprintln(w, rand.Intn(100)+1)
	}
	w.Flush()
}
