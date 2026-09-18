mod bench;
mod circuit;
mod gen;
mod json;
mod vectors;
mod verify;

use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "groth16-ref", about = "arkworks Groth16/BN254 reference harness for bend-groth16")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Setup + witness + reference proof for SquareChain(2^K) → frozen JSON under --out.
    Gen {
        #[arg(long)]
        log2: u32,
        #[arg(long)]
        out: PathBuf,
    },
    /// Verify a proof (frozen JSON encoding). Prints OK (exit 0) or INVALID (exit 1).
    Verify {
        #[arg(long)]
        vk: PathBuf,
        #[arg(long)]
        proof: PathBuf,
        #[arg(long)]
        public: PathBuf,
    },
    /// Primitive test vectors (Fr/Fq ops, G1/G2 ops, small MSM/NTT).
    Vectors {
        #[arg(long)]
        out: PathBuf,
    },
    /// Benchmark arkworks. `--log2 K` = Groth16::prove at 2^K (reuses data/K/pk.bin if present);
    /// `--primitives` = MSM/NTT/Fr-mul suites. Results merge into <out-dir>/arkworks-<host>.json.
    Bench {
        #[arg(long)]
        log2: Option<u32>,
        #[arg(long)]
        primitives: bool,
        /// Iterations per measurement (default: 3 below 2^16, else 1; median reported).
        #[arg(long)]
        iters: Option<usize>,
        /// Largest MSM/NTT size (log2) for --primitives.
        #[arg(long, default_value_t = 20)]
        max_log2: u32,
        #[arg(long, default_value = "data")]
        data: PathBuf,
        #[arg(long, default_value = "bench")]
        out_dir: PathBuf,
    },
}

fn main() {
    let cli = Cli::parse();
    let res = match cli.cmd {
        Cmd::Gen { log2, out } => gen::run(log2, &out),
        Cmd::Verify { vk, proof, public } => match verify::run(&vk, &proof, &public) {
            Ok(true) => {
                println!("OK");
                return;
            }
            Ok(false) => {
                println!("INVALID");
                std::process::exit(1);
            }
            Err(e) => {
                eprintln!("error: {e}");
                println!("INVALID");
                std::process::exit(1);
            }
        },
        Cmd::Vectors { out } => vectors::run(&out),
        Cmd::Bench { log2, primitives, iters, max_log2, data, out_dir } => {
            let mut r = Ok(());
            if let Some(k) = log2 {
                r = bench::prove(k, iters, &data, &out_dir);
            }
            if r.is_ok() && primitives {
                r = bench::primitives(iters, &out_dir, max_log2);
            }
            if log2.is_none() && !primitives {
                r = Err("bench: pass --log2 K and/or --primitives".into());
            }
            r
        }
    };
    if let Err(e) = res {
        eprintln!("error: {e}");
        std::process::exit(2);
    }
}
