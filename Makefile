# Callout CAD — Build System
#
# Targets:
#   make          — Build everything (C server + OCaml core + frontend)
#   make server   — Build C server only
#   make ocaml    — Build OCaml core + frontend
#   make test     — Run OCaml test suite
#   make clean    — Remove build artifacts
#   make run      — Build and start server

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------

CC        = gcc
CFLAGS    = -Wall -Werror -Wextra -pedantic -std=c11 -O2
CFLAGS   += -I src/server -I vendor

# OCaml stdlib location for caml/ headers and libasmrun
OCAML_STDLIB := $(shell ocamlfind printconf stdlib)
CFLAGS   += -I $(OCAML_STDLIB)

LDFLAGS   = -lpthread -lws2_32

# Our source files (compiled with strict warnings)
SERVER_OBJ = build/main.o \
             build/http.o \
             build/ws.o \
             build/db.o \
             build/bridge.o

# Vendored deps (compiled without -Werror)
VENDOR_OBJ = build/mongoose.o \
             build/sqlite3.o

# OCaml bridge object (produced by ocamlopt -output-obj)
BRIDGE_FFI_OBJ = build/bridge_ffi.o

SERVER_BIN = build/callout-server

# -------------------------------------------------------------------
# Top-level targets
# -------------------------------------------------------------------

.PHONY: all server ocaml client test clean run setup harness bench stress bridge-ffi

all: server ocaml client

# -------------------------------------------------------------------
# OCaml bridge FFI object
# -------------------------------------------------------------------

bridge-ffi: ocaml
	@mkdir -p build
	ocamlfind ocamlopt -package callout-bridge -linkpkg -output-obj \
		-o $(BRIDGE_FFI_OBJ)
	@echo "==> Built OCaml bridge FFI object: $(BRIDGE_FFI_OBJ)"

# -------------------------------------------------------------------
# C Server
# -------------------------------------------------------------------

server: bridge-ffi $(SERVER_OBJ) $(VENDOR_OBJ)
	$(CC) -o $(SERVER_BIN) $(SERVER_OBJ) $(VENDOR_OBJ) $(BRIDGE_FFI_OBJ) \
		-L$(OCAML_STDLIB) -lasmrun -lunix \
		$(LDFLAGS)
	@echo "==> Built C server: $(SERVER_BIN)"

# Our code: strict warnings
build/%.o: src/server/%.c | build
	$(CC) $(CFLAGS) -c $< -o $@

# Vendored mongoose: relaxed warnings
build/mongoose.o: vendor/mongoose.c | build
	$(CC) -std=c11 -O2 -I vendor -c $< -o $@

# Vendored sqlite3: relaxed warnings
build/sqlite3.o: vendor/sqlite3.c | build
	$(CC) -std=c11 -O2 -I vendor -c $< -o $@

build:
	@mkdir -p build

# -------------------------------------------------------------------
# OCaml (core library + client frontend)
# -------------------------------------------------------------------

ocaml:
	dune build @all
	@echo "==> Built OCaml core"

client: ocaml
	@mkdir -p static
	@if [ -f _build/default/src/client/app.bc.js ]; then \
		rm -f static/app.bc.js; \
		cp _build/default/src/client/app.bc.js static/app.bc.js; \
		chmod 644 static/app.bc.js; \
		echo "==> Copied frontend JS to static/app.bc.js"; \
	fi

# -------------------------------------------------------------------
# Tests
# -------------------------------------------------------------------

test:
	dune runtest --force
	@echo "==> All tests passed"

# -------------------------------------------------------------------
# Harness (headless engine stress testing)
# -------------------------------------------------------------------

harness:
	dune build src/harness/harness.exe

bench: harness
	dune exec callout-harness -- --test 100000 --seed 42

stress: harness
	dune exec callout-harness -- --stress --seed 42

# -------------------------------------------------------------------
# Run
# -------------------------------------------------------------------

run: all
	./$(SERVER_BIN) -r ./static -d callout.db

# -------------------------------------------------------------------
# Setup (first-time)
# -------------------------------------------------------------------

setup:
	@echo "Installing OCaml dependencies..."
	opam install dune js_of_ocaml js_of_ocaml-ppx js_of_ocaml-lwt alcotest yojson --yes
	@echo ""
	@echo "Downloading Mongoose..."
	@mkdir -p vendor
	@echo "Download mongoose.c and mongoose.h from https://github.com/cesanta/mongoose"
	@echo "and place them in the vendor/ directory."
	@echo ""
	@echo "Downloading Leaflet..."
	@echo "Download leaflet.js and leaflet.css from https://leafletjs.com"
	@echo "and place them in the static/leaflet/ directory."

# -------------------------------------------------------------------
# Clean
# -------------------------------------------------------------------

clean:
	rm -rf build _build
	rm -f static/app.bc.js
	rm -f callout.db callout.db-wal callout.db-shm
	dune clean 2>/dev/null || true
	@echo "==> Cleaned"
