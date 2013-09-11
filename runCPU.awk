#!bin/awk
BEGIN{
    srand();
    x=rand();
    n=0;
    for(;;)
    {
        x=4*x*(1-x)
        if(++n==1e6){
            print x;
            n=0;
        }
    }
}
