import os
Import("env")

# pioarduino resolves toolchain-riscv32-esp through a global .pio-link symlink,
# whose bin/ is not placed on the build PATH. Prepend the real toolchain bin so
# riscv32-esp-elf-g++ resolves. Project-local; touches nothing outside this build.
candidates = [
    os.path.expanduser("~/.platformio/tools/toolchain-riscv32-esp/bin"),
    os.path.expanduser("~/.platformio/packages/toolchain-riscv32-esp/bin"),
]
for path in candidates:
    if os.path.isfile(os.path.join(path, "riscv32-esp-elf-g++")):
        env.PrependENVPath("PATH", path)
        print("[c5] toolchain PATH += %s" % path)
        break
