// SPDX-License-Identifier: GPL-3.0-or-later
#include "input.hpp"
#include <cassert>
#include <cstdio>
int main() {
    DoomInput::State state;int down;unsigned char code;
    state.set(1,42,true);state.set(1,42,true);
    assert(state.pop(&down,&code) && down==1 && code==42);assert(!state.pop(&down,&code));
    state.set(2,42,true);state.set(1,42,false);assert(!state.pop(&down,&code));
    state.set(2,99,false);assert(state.pop(&down,&code) && !down && code==42);
    state.set(3,56,true);state.set(4,57,true);state.releaseAll();
    unsigned presses=0,releases=0;while (state.pop(&down,&code)) down?++presses:++releases;
    assert(presses==2 && releases==2);
    state.set(3,56,false);assert(!state.pop(&down,&code));
    state.set(9999,99,true);state.set(1,0,true);assert(!state.pop(&down,&code));
    std::puts("PASS key repeat, aliased controls, release after menu transition, focus loss, invalid source");
}
