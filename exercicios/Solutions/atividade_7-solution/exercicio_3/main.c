#include <stdio.h>
#include <time.h>
#include <math.h>
#include <omp.h>
#include <stdlib.h>

double standard_deviation(double* data, int size) {
    double avg = 0;
    #pragma omp parallel for reduction(+:avg)
    for (int i = 0; i < size; ++i) 
        avg += data[i]/size;

    double sd = 0;
    #pragma omp parallel for reduction(+:sd)
    for (int i = 0; i < size; ++i) 
        sd += pow(data[i] - avg, 2) / (size-1);
    sd = sqrt(sd);

    return sd;
}
 
int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Uso: %s tamanho\n", argv[0]);
        return 1;
    }
    int tamanho = atoi(argv[1]);
    
    double* data = malloc(tamanho*sizeof(double));

    unsigned int st = time(NULL);
    #pragma omp parallel for firstprivate(st)
    for (unsigned int i = 0; i < tamanho; ++i) {
        if (i == 0) st *= omp_get_thread_num();
        data[i] = 100000*(rand_r(&st)/(double)RAND_MAX);
    }
    
    printf("sd: %g\n", standard_deviation(data, tamanho));

    free(data);

    return 0;
}
