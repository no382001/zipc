r0-r3 holds args and retval and calls can overwrite them, r12 does something aswell so i could keep the zip registers in r4-r11 and then call to zip_unify(a, b) so i can mix c and handrolled assembly easy, any other time when i need to transfer to c, i can just dump the state then restore it later

arm-none-eabi-gcc -mcpu=cortex-m33 -O2 -S

targeting thumb-2 arm, what do i do with the other processor? probably just run the uart there

todo: 
- write a zip prototype in c
- assess the general shape
- handroll most of it in thumb-2 assmebly, exept things that need excessive juggling