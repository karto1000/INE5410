/*!
      É utilizado para paralelizar pedaços do código que está na região paralela.
      Cada secao definida será executada por um thread

      #pragma omp sections [atributos]
                            private(var1, var2,...)
                            firstprivate(var1, var2,...)
                            reduction(operador: var1, var2,...)
                            nowait

      BIBLIOTECAS:          #include <stdio.h>
                            #include <stdlib.h>
                            #include <omp.h>
                            #include <time.h>

      COMPILADOR:           $ gcc sections.c -fopenmp -o program
                            $ ./program 4 300

*/
#include <stdio.h>
#include <stdlib.h>  // atoi
#include <omp.h>  // OpenMp
#include <time.h>  // clock_t

int main (int argc, char **argv) {

  if(argc < 3 || argc > 3) {
    printf("Error: expected -> ./program 'num_threads' 'numero_iteracoes'\n");
  } else {
    int n = atoi(argv[1]);  // numero de iteracoes
    int num_threads = atoi(argv[2]);
    int a[n], b[n], c[n], d[n];
    int e[n], f[n], g[n], h[n];
    int soma_seq =0, mult_seq=0, sub_seq=0, res_seq=0;
    int soma_paral=0, mult_paral=0, sub_paral=0, res_paral =0;

    for (int i=0; i<n;i++) {
      a[i] = i;
      e[i] = i;

      b[i] = i+1;
      f[i] = i+1;

      c[i] = i-1;
      g[i] = i-1;

      d[i] = i*i;
      h[i] = i*i;
    }
    clock_t begin_seq  = clock();
    for(int i =0; i<n; i++) {
      soma_seq += a[i] *b[i];
    }

    for(int i =0; i<n; i++) {
      sub_seq -= c[i]*d[i];
    }

    for (int i = 0; i<n; i++) {
      mult_seq *= a[i]*d[i];
    }

    res_seq = soma_seq + sub_seq + mult_seq;

    clock_t end_seq = clock();

    double time_spent_seq = (double) (end_seq - begin_seq)/CLOCKS_PER_SEC;

    omp_set_num_threads(num_threads);
    clock_t begin_paralel = clock();
    #pragma omp parallel  shared (soma_paral, sub_paral, mult_paral)//reduction(+:soma_paral, mult_paral, sub_paral)
    {
      #pragma omp sections
      {
        #pragma omp section
        {
          for(int i = 0; i<n; i++) {
            soma_paral += e[i] *f[i];
          }
        }

        #pragma omp section
        {
          for(int i = 0; i<n; i++){
            sub_paral -= g[i]*h[i];
          }
        }

        #pragma omp section
        {
          for(int i =0; i<n;i++) {
            mult_paral *= e[i]*h[i];
          }
        }

      }  // end sections

    }  // end parallel
    res_paral = soma_paral+sub_paral+mult_paral;
    clock_t end_paralel = clock();

    double time_spent_paralel = (double) (end_paralel - begin_paralel)/CLOCKS_PER_SEC;

    printf("res_seq: %d\n", res_seq);
    printf("res_paral: %d\n\n", res_paral);

    printf("time_spent_seq: %f\n", time_spent_seq);
    printf("time_spent_paralel: %f\n", time_spent_paralel);
  }


  return 0;
}
