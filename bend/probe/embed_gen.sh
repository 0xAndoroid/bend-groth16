#!/bin/sh
# Generate a Bend 1 program embedding N u24 literals as a List and summing it.
# usage: embed_gen.sh N > embed_N.bend
N=${1:-16384}
echo "# generated: $N embedded u24 literals"
echo "def sum(xs):"
echo "  match xs:"
echo "    case List/Nil:"
echo "      return 0"
echo "    case List/Cons:"
echo "      return xs.head + sum(xs.tail)"
echo ""
echo "def data():"
printf "  return ["
awk -v n="$N" 'BEGIN{srand(1); for(i=0;i<n;i++){ if(i) printf ","; printf "%d", int(rand()*16777216) }}'
echo "]"
echo ""
echo "def main():"
echo "  return sum(data())"
