#include <stdio.h>

int main () {

	int x = 1, y = 2, z[10];
	int *ip_x, *ip_y;
	int *ip_z;

	printf("ip_x adress: %p\n", &ip_x);

	printf("x adress: %p\n", &x);
	printf("x value: %d\n",x);

	printf("y adress: %p\n", &y);
	printf("y value: %d\n", y);

	printf("z adress: %p\n", &z);

	printf("z values: ");
	for(int i = 0; i < 10;i++) {
		printf("[%d]: %d \n", i, z[i]);
	}
	

	// y = *ip;
	// *ip = 0;
	// ip = &z[0];

	return 0;
}