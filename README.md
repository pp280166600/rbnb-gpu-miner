# rBNB铭文GPU挖矿程序
基于keccak-256(sha3)算法的挖矿程序，挖矿速度是CPU的几十倍，执行完成后生成符合条件的hash文本

# Build(Windows)
```
nvcc *.cu -dc
nvcc *.obj -o main.exe
```
# Use(Windows)
```
main.exe -a "address" -m "rBNB"
```
