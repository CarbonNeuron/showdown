const n = parseInt(process.argv[2]);
const lines = [];
for (let i = 0; i < n; i++) {
    lines.push(String(Math.floor(Math.random() * 100) + 1));
}
process.stdout.write(lines.join('\n') + '\n');
