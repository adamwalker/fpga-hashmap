use walkdir::WalkDir;
use cmake::Config;

fn main() {

    //Rerun if the C++ sources change
    println!("cargo:rerun-if-changed=lib.cpp");
    println!("cargo:rerun-if-changed=lib.hpp");

    //Rerun if verilog sources change
    for entry in WalkDir::new("../src")
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|f| f.file_type().is_file()) 
    {
        println!("cargo:rerun-if-changed={}", entry.path().display());
    }

    //Verilate with CMake
    let dst = Config::new("../src")
        .generator("Ninja") //As recommended by verilator
        .build();

    cxx_build::bridge("src/main.rs")
        .file("src/lib.cpp")
        .include(dst.join("include"))
        .flag("-Wno-unused-parameter")
        .compile("sim");
    
    println!("cargo:rustc-link-search={}/lib", dst.display());
    println!("cargo:rustc-link-lib=sim");
    println!("cargo:rustc-link-lib=Vkvs");
}
