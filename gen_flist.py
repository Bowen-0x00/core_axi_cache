#!/usr/bin/env python3
import os
import sys

def generate_filelist(root_dir):
    incdirs = set()
    filelist = []

    for dirpath, dirnames, filenames in os.walk(root_dir):
        abs_dir = os.path.abspath(dirpath)

        # include 文件夹直接加
        if os.path.basename(dirpath) == "include":
            incdirs.add(abs_dir)

        for f in filenames:
            if f.endswith(".v") or f.endswith(".sv"):
                file_path = os.path.join(abs_dir, f)
                filelist.append(os.path.abspath(file_path))

                # 文件名去后缀判断
                base_name = os.path.splitext(f)[0]
                if base_name.endswith("defines") or base_name.endswith("pkg"):
                    incdirs.add(abs_dir)

    # 输出 include 目录
    for inc in sorted(incdirs):
        print(f"+incdir+{inc}")

    # 输出文件路径
    for f in sorted(filelist):
        print(f)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <directory>")
        sys.exit(1)
    generate_filelist(sys.argv[1])
