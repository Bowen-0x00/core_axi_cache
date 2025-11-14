import sys

def gen_hex_file(filename, length):
    with open(filename, "w") as f:
        for i in range(1, length + 1):
            f.write(f"{i & 0xFF:02X}\n")  # 每行写一个8-bit数据（两位HEX）
    print(f"✅ 已生成 {filename}，共 {length} 行。")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法: python gen_hex.py <输出文件名> <长度LEN>")
        print("示例: python gen_hex.py data.hex 256")
        sys.exit(1)
    
    filename = sys.argv[1]
    length = int(sys.argv[2])
    gen_hex_file(filename, length)
