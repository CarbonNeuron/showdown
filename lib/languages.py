"""Language registry for the showdown framework."""

LANGUAGES = {
    "c":            {"ext": "c",      "name": "C",              "compiled": True},
    "cpp":          {"ext": "cpp",    "name": "C++",            "compiled": True},
    "rust":         {"ext": "rs",     "name": "Rust",           "compiled": True},
    "go":           {"ext": "go",     "name": "Go",             "compiled": True},
    "java":         {"ext": "java",   "name": "Java",           "compiled": True},
    "csharp":       {"ext": "cs",     "name": "C# (Mono)",      "compiled": True},
    "dotnet":       {"ext": "cs",     "name": "C# (.NET)",      "compiled": True},
    "dotnet-aot":   {"ext": "cs",     "name": "C# (AOT)",       "compiled": True},
    "python":       {"ext": "py",     "name": "Python",         "compiled": False},
    "ruby":         {"ext": "rb",     "name": "Ruby",           "compiled": False},
    "javascript":   {"ext": "js",     "name": "JavaScript",     "compiled": False},
    "typescript":   {"ext": "ts",     "name": "TypeScript",     "compiled": False},
    "kotlin":       {"ext": "kt",     "name": "Kotlin",         "compiled": True},
    "swift":        {"ext": "swift",  "name": "Swift",          "compiled": True},
    "zig":          {"ext": "zig",    "name": "Zig",            "compiled": True},
    "nim":          {"ext": "nim",    "name": "Nim",            "compiled": True},
    "d":            {"ext": "d",      "name": "D",              "compiled": True},
    "haskell":      {"ext": "hs",     "name": "Haskell",        "compiled": True},
    "ocaml":        {"ext": "ml",     "name": "OCaml",          "compiled": True},
    "erlang":       {"ext": "erl",    "name": "Erlang",         "compiled": False},
    "elixir":       {"ext": "exs",    "name": "Elixir",         "compiled": False},
    "lua":          {"ext": "lua",    "name": "Lua",            "compiled": False},
    "perl":         {"ext": "pl",     "name": "Perl",           "compiled": False},
    "php":          {"ext": "php",    "name": "PHP",            "compiled": False},
    "scala":        {"ext": "scala",  "name": "Scala",          "compiled": True},
    "fortran":      {"ext": "f90",    "name": "Fortran",        "compiled": True},
    "ada":          {"ext": "adb",    "name": "Ada",            "compiled": True},
    "pascal":       {"ext": "pas",    "name": "Pascal",         "compiled": True},
    "bash":         {"ext": "sh",     "name": "Bash",           "compiled": False},
    "awk":          {"ext": "awk",    "name": "AWK",            "compiled": False},
    "dart":         {"ext": "dart",   "name": "Dart",           "compiled": True},
    "crystal":      {"ext": "cr",     "name": "Crystal",        "compiled": True},
}


def get_all_language_keys():
    return list(LANGUAGES.keys())


def resolve_languages(lang_spec):
    spec = lang_spec.strip().lower()
    if spec == "all":
        return get_all_language_keys()
    keys = [k.strip() for k in spec.split(",")]
    unknown = [k for k in keys if k not in LANGUAGES]
    if unknown:
        raise ValueError(f"Unknown languages: {', '.join(unknown)}")
    return keys


def get_language(key):
    return LANGUAGES[key]
