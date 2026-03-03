use std::env;
use std::io::{self, Write, BufWriter};
use std::time::{SystemTime, UNIX_EPOCH};

fn main() {
    let args: Vec<String> = env::args().collect();
    let n: usize = args[1].parse().expect("Usage: solution N");
    let mut out = BufWriter::new(io::stdout().lock());
    let mut seed: u64 = SystemTime::now()
        .duration_since(UNIX_EPOCH).unwrap()
        .as_nanos() as u64;
    for _ in 0..n {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let val = (seed >> 33) % 100 + 1;
        writeln!(out, "{}", val).unwrap();
    }
}
