// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <array>
#include <deque>
namespace DoomInput {
class State {
    std::array<unsigned char,512> sources{};
    std::array<unsigned,256> references{};
    std::deque<unsigned> events;
public:
    void set(unsigned source,unsigned char action,bool down) {
        if (source>=sources.size()) return;
        if (down) {
            if (!action || sources[source]) return;
            sources[source]=action;
            if (references[action]++==0) events.push_back(action|256);
        } else {
            action=sources[source];if (!action) return;
            sources[source]=0;
            if (--references[action]==0) events.push_back(action);
        }
    }
    void releaseAll() {
        for (unsigned action=1;action<references.size();++action)
            if (references[action]) events.push_back(action);
        sources.fill(0);references.fill(0);
    }
    bool pop(int* down,unsigned char* action) {
        if (events.empty()) return false;
        unsigned value=events.front();events.pop_front();*down=value>>8;*action=value&255;return true;
    }
};
}
