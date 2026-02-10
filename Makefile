CC       = gcc
CFLAGS   = -Wall -Werror -Wextra -pedantic -std=c11 -O2
CFLAGS  += -I src/server -I vendor

OCAML_STDLIB := $(shell ocamlfind printconf stdlib)
CFLAGS  += -I $(OCAML_STDLIB)

SERVER_OBJ = build/main.o build/http.o build/ws.o build/db.o build/bridge.o
VENDOR_OBJ = build/mongoose.o build/sqlite3.o build/crypt_blowfish.o
BRIDGE_FFI_OBJ = build/bridge_ffi.o
SERVER_BIN = build/callout-server

ifeq ($(OS),Windows_NT)
FLEXDLL_DIR := $(OCAML_STDLIB)/flexdll
LINK      = flexlink -chain mingw64 -exe -I $(FLEXDLL_DIR)
LINK_LIBS = -L$(OCAML_STDLIB) -lasmrun -lunixnat -lws2_32 -ladvapi32 -lpthread -lole32 -lshlwapi -lversion -lsynchronization -lshell32 -luuid
else
LINK      = $(CC)
LINK_LIBS = -L$(OCAML_STDLIB) -lasmrun -lunix -lpthread
endif

.PHONY: all server ocaml client test clean run setup harness bench stress bridge-ffi

all: server ocaml client

bridge-ffi: ocaml
	@mkdir -p build
	OCAMLPATH=_build/install/default/lib \
		ocamlfind ocamlopt -package callout-bridge -linkpkg -linkall \
		-output-obj -o $(BRIDGE_FFI_OBJ)

server: bridge-ffi $(SERVER_OBJ) $(VENDOR_OBJ)
	$(LINK) -o $(SERVER_BIN) $(SERVER_OBJ) $(VENDOR_OBJ) $(BRIDGE_FFI_OBJ) $(LINK_LIBS)

build/%.o: src/server/%.c | build
	$(CC) $(CFLAGS) -c $< -o $@

build/mongoose.o: vendor/mongoose.c | build
	$(CC) -std=c11 -O2 -I vendor -c $< -o $@

build/sqlite3.o: vendor/sqlite3.c | build
	$(CC) -std=c11 -O2 -I vendor -c $< -o $@

build/crypt_blowfish.o: vendor/crypt_blowfish.c | build
	$(CC) -std=c11 -O2 -I vendor -c $< -o $@

build:
	@mkdir -p build

ocaml:
	dune build @all

client: ocaml
	@mkdir -p static
	@if [ -f _build/default/src/client/app.bc.js ]; then \
		rm -f static/app.bc.js; \
		cp _build/default/src/client/app.bc.js static/app.bc.js; \
		chmod 644 static/app.bc.js; \
	fi

test:
	dune runtest --force

harness:
	dune build src/harness/harness.exe

bench: harness
	dune exec callout-harness -- --test 100000 --seed 42

stress: harness
	dune exec callout-harness -- --stress --seed 42

run: all
	./$(SERVER_BIN) -r ./static -d callout.db

setup:
	opam install dune js_of_ocaml js_of_ocaml-ppx js_of_ocaml-lwt alcotest yojson --yes

clean:
	rm -rf build _build
	rm -f static/app.bc.js
	rm -f callout.db callout.db-wal callout.db-shm
	dune clean 2>/dev/null || true
