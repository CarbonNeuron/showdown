#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char *argv[]) {
    if (argc != 2) { fprintf(stderr, "Usage: solution N\n"); return 1; }
    int n = atoi(argv[1]);
    srand(time(NULL));
    char buf[65536];
    setvbuf(stdout, buf, _IOFBF, sizeof(buf));
    for (int i = 0; i < n; i++)
        printf("%d\n", (rand() % 100) + 1);
    return 0;
}
