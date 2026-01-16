#!/usr/bin/env python
import sys
from pathlib import Path
from itertools import chain
from compression import zstd
from compression.zstd import CompressionParameter

from tqdm import tqdm


LEVELS = list(chain(range(-7, 0), range(1, 19 + 1)))
THREADS = 13  # TODO: decide what to do with threading

def compress_file(path_in, path_out, level, threads):
    options = {CompressionParameter.nb_workers: threads,
               CompressionParameter.compression_level: level}

    original = Path(path_in).read_bytes()

    with zstd.open(path_out, mode='w', options=options) as file:
        file.write(original)


def main(dir_in, dir_out):
    print(f'Compressing data from {dir_in} to {dir_out}')
    for level in tqdm(LEVELS, initial=min(LEVELS)):
        level_path = Path(dir_out) / str(level)
        level_path.mkdir(exist_ok=True)

        files = sorted(Path(dir_in).iterdir())
        for orig_path in tqdm(files, leave=False):
            compress_path = f'{level_path / orig_path.name}.zst'
            compress_file(orig_path, compress_path, level, THREADS)
    print('Compression done!')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: gen_zstd.py PATH_IN PATH_OUT")
        exit(2)
    main(*sys.argv[1:])
