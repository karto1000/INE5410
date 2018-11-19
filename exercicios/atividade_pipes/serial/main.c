#include "dagostrophism.h" 
#include <stdio.h>

int is_dagostrophic(const char* str);

int main(int argc, char** argv) {
    int total = 0;
    char word[4096];
    while (scanf("%4096s", word) > 0) {
        total += is_dagostrophic(word);
    }
    printf("Palavras dagostróficas: %d\n", total);
}


