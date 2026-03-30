#!/usr/bin/env python3
"""Fix dangling pointer crash in PanicComponent::execute.

The cached pArmedPed_ pointer can reference a freed PedInstance,
causing a general protection fault when dereferenced. This patch
replaces the stale cache check with a fresh lookup every tick.
"""
import sys

content = open(sys.argv[1]).read()

old = """void PanicComponent::execute(const Behaviour::BehaviourParam &param) {
    if (status_ == kPanicStatusCalm && scoutTimer_.update(param.elapsed)) {
        // Check if threat is dead \u2014 immediately calm down
        if (pArmedPed_ != nullptr && !pArmedPed_->isAlive()) {
            pArmedPed_ = nullptr;
            backFromPanic_ = false;
            param.pPed->setInPanic(false);
            param.pPed->setCurrentActionWithSource(Action::kActionDefault);
            status_ = kPanicStatusCalm;
            return;
        }

        pArmedPed_ = findNearbyArmedPed(param.pMission, param.pPed);"""

new = """void PanicComponent::execute(const Behaviour::BehaviourParam &param) {
    if (!param.pPed || !param.pMission) return;
    if (status_ == kPanicStatusCalm && scoutTimer_.update(param.elapsed)) {
        // Always re-lookup armed ped to avoid dangling pointer crashes.
        // The cached pArmedPed_ may point to a freed PedInstance.
        pArmedPed_ = findNearbyArmedPed(param.pMission, param.pPed);"""

if old in content:
    content = content.replace(old, new)
    open(sys.argv[1], 'w').write(content)
    print("Patched PanicComponent::execute")
else:
    print("ERROR: Could not find patch target in " + sys.argv[1], file=sys.stderr)
    sys.exit(1)
