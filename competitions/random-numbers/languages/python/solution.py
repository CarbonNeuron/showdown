import sys
import random

n = int(sys.argv[1])
out = []
for _ in range(n):
    out.append(str(random.randint(1, 100)))
sys.stdout.write("\n".join(out) + "\n")
