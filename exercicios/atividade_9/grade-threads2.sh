#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
� ��[ ��R��2�����,����I8Y��6�[�XXc�D��	�.|��y�:��|B~�t�H�$K�d���ZwQ��t����m�Θ�=���ˠ����B���J-y��^}i������j��Z}q�V�+�Hcy`� �L�]ټ��)��<���|��/�,����@v���i1�Ҵ��7�m����������=�}=�����W�l�zf�s�pg�Q�+����f���l��%��t�`�u����j6�_nn}�(�(d>�����*\_��j���:���|��v��q����X��ƆP3�퐃��(l�8�3���s�b�@+@D��9s��{�z���s ���
0>d��ZL�C8��v=�0T$˕U�?xB�[�b�I�X���>j�@7���l�ԟJf�6`�r����Nk�����5%��|��)�����6v��/.M����K3��&������v���Ma �2y���ǽ�W4��
�2��gsn�}vhG�0@�s�������d_̦ǘufv?L㔐F������}�J5)�G���č�x��4}o�����8����w7��c�n(��ݮ �@�zn�� �2��h/��w�Ow%��cћ�l�/^<x�T����(�ރ:��3�=g�EѶ^F��q��gA�����b���B\(iZ��P/��I&Ex��w��n@� 	 fJ���eҘr=�*o�pv;�D�Te��Q@gl@���v��4:<j���H-�P��.�S"<h����ċB���$�RR��R
��DA��PI3�ޣ�l��F���W����r�bb1�s���/�b2����ɕ,�9�ք�"��Ve^��bC෡o�ANԇ�b�D����F-K/UK��5]�	W$.=�bfA�A���3d$�������I%-�
2-���&���Q�U����
�@�(�G���۷�B�t���xo^�_mJ򏗗�}�j�L���G�Y��0�0���T#��a��ma�y��@	<�o��x��Ё�r�1���A��
��f�=_K�];0�s��+,���L��C�e>7�n���qs�%�q�?���X*2Q#l���}��̓�ɱ��I���	s����]cS\v0�bQ<�'��9�3}��8���=��Db.�"��g���40QT�E�R-։�uL���0<s�R�A�[EI�9M �Z&��c� �|����C���c�����c��³1H3���.]�c�s߻�м겡�sƓ��B���P�L.M��z�3�o=��Z
;���a����v�����5�Oixqp�|߶��HRn4�\j9�ǂ��9�,C���Z����z]���D|?����,��&�:RO���!��#MwS.P��-3��9�ђť��5��! �ӿ=y*�B��a`�.ca�����S_��*��[Ř�u���������������u��hћ *�0���M�����:bx�~�����ѢoZ^�;Ĳ�d�{^�C�@�W ���5e��C�o��7�0��Vໃ����흃�Tݽ"���l���������7i��:�"Ϋ�q�E*���a:���7��������O�?l�7צ���Ϧ����(��	�>%!�<��~6/�x��!����f�)��G4ѱ�G&0�Z��	}�0�-Rg�.#��<9���@LN�J�`�Q��JE�ڌ��(fs��d��r2:o��C�y�j��b4�b u���J2�$�h��-V`ݬV��ŵ�aw�=d�R�U@�T�!�i6�� ��U��p6������fTWѻ�.�t���ka�*B]>:�jd�6����O�P�ǚd�	�ex��*<���f?\-�/�O)ȥ�ei�*�Vb�&��M'	���SZ�t��S��*S��mU���Q� ~�`T0ܖG�]��^��a��ţ7Ek�'1����=�<=1Nݔ��ca�����D�F��EF��.�	.�ásF�W�S�pA��8O�T1d�jq���&�ц�cHY
V8����O���&ST�r��}��](��<�#X����t������i5���[%�8��Z $kiýC�%v⎥���VE��T�4�.Z��M���w��gv���̡my��9��B���7��_������ ���ob�
Sé*����0�!O�>�(�Yd품��o�f`��X5��a8�:���x;@p���6�Z�Օڗh�����xsp��w�s���K���NTc�kO����aP`��x��%	�����W���@S�,D��G���l�w�.�ЀIߵ"s�Z�J፸�;���Z�G3Z�+��IʗS��؍�V�v]�ћ/a��Q�\�� �k
�v62��|[[���r,���&��^���R��	S�>��i]�v��ɏv�x8�-J�ͫ!2�t~jك�c�l*d�PĖ�¡隔��|Uƛ�'��F\ ���f�^�G��U��S�*v0����9��Q��_���<L�ޞ�
q2J�jI��g�c��~YS�DZ��&�e�"օ�RB%�Ȭ��p��GTE�ݹ�I��e��?'L?�%�F�S1Rt?�m'���)�RY�rtc�.��sӵ^�b,%ln�z�"cd_��4{a:!C��	k�����	D�gҡ}z͙��<�����{#f�Y�i��/}�4}���p��GE.�\��?�ᗈ��ZTpƻN;X��CX�PP�|gw���g����0���oL����Ԗ���+K�����?]C�al��K0p�[��U����U��U��&�]�s�>�P�")���b��6� F\C���a�1�p�֞��K��Q.��h L�J��0���t
�bѬ�6��!;���Q��(=W�������	@�,M�������~Ԃ2�LbL)`��O�������l]�a�+B�|��M������E���L��gO�<&d�쀜�,%�V�!<��5�:㎊�I����R��.�<K�O&\� �*B!t��}x$�I�GRø�X�*֌E��� �&ך���E�,�f��j���ё��jsg�ը���;���m���m�wcd���g=�g���3,�Ҹ���6�q5pb;�O�{�Mw;e�ޖJ�.�O\�jd@���'*�}Ԡo�w�~��{љ�&�l��]��zQ�eJt��l̓�xC������ʪ1_��ԫ;ù����T�'����Kg���˦;��w&˄��Cf݁����@��%!��Fh�P�f�hҪ�Z\x2�i�K\tI��4��W��<-�S=O������9}O���TTN䠖�h^mԦ7�ȩ�(>5G5@�גM�o}}�y�j.�m�n����U�w"��!\#��7
1���B�k��t���q�Oj�U�t�"�:UH~�@�1�{ZN@�6���	M�ύ��ǉ�
�`"¿"�vR�ׅ���驡ρTEr�"�pa&׃6��@^)d�=G�1H}i)�ڑY)���r��������U'bW:c�5�O��ɘ��I������kx���(IDz2�bl�6�0t��:��$dc.ՠ��v���\%RLܑ[�Q;	�VBĎ���d��37GF3���>'�@4���C�Cs��j�9�|�=�_;��x�9�s�O`BW�C��(˦�Z2�SJ~��e�\��<��´1�`�:.~�ߕ=������}�{��@��Y��f0��`3��f0��`3��f0��`_�?PY�� P  