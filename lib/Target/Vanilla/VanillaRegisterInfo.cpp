//===-- VanillaRegisterInfo.cpp - Vanilla Register Information ----------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file contains the Vanilla implementation of the TargetRegisterInfo class.
//
//===----------------------------------------------------------------------===//

#include "Vanilla.h"
#include "VanillaRegisterInfo.h"
#include "VanillaSubtarget.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/RegisterScavenging.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Target/TargetFrameLowering.h"
#include "llvm/Target/TargetInstrInfo.h"
#include "llvm/Support/raw_ostream.h"

#define GET_REGINFO_TARGET_DESC
#include "VanillaGenRegisterInfo.inc"
using namespace llvm;

VanillaRegisterInfo::VanillaRegisterInfo()
    : VanillaGenRegisterInfo(Vanilla::R0) {}

const MCPhysReg *
VanillaRegisterInfo::getCalleeSavedRegs(const MachineFunction *MF) const {
  return CSR_SaveList;
}

const uint32_t *
VanillaRegisterInfo::getCallPreservedMask(const MachineFunction &MF,
                                        CallingConv::ID CC) const {
  return CSR_RegMask;
}

BitVector VanillaRegisterInfo::getReservedRegs(const MachineFunction &MF) const {
  BitVector Reserved(getNumRegs());
  Reserved.set(Vanilla::R1);//temporary reg
  Reserved.set(Vanilla::R0);//frame pointer
  Reserved.set(Vanilla::R3);//stack pointer
  return Reserved;
}

void VanillaRegisterInfo::eliminateFrameIndex(MachineBasicBlock::iterator II,
                                          int SPAdj, unsigned FIOperandNum,
                                          RegScavenger *RS) const {
  assert(SPAdj == 0 && "Unexpected");
  
  unsigned i = 0;
  MachineInstr &MI = *II;
  MachineFunction &MF = *MI.getParent()->getParent();
  DebugLoc DL = MI.getDebugLoc();
  const VanillaSubtarget &Subtarget = MF.getSubtarget<VanillaSubtarget>();
  
  while (!MI.getOperand(i).isFI()) {
    ++i;
    assert(i < MI.getNumOperands() && "Instr doesn't have FrameIndex operand!");
  }
  
  unsigned baseReg = MF.getSubtarget().getFrameLowering()->hasFP(MF)?getFrameRegister(MF):Vanilla::R3;
  int FrameIndex = MI.getOperand(i).getIndex();
  
  int Offset = MF.getFrameInfo()->getObjectOffset(FrameIndex);
  
  //MI.dump();
  //errs()<<"FrameIndex:"<<FrameIndex<<"\n";
  //errs()<<"Offset:"<<Offset<<"\n";
  
  if(isInt<11>(Offset)){
    //MOVI R1, Offset
    //ADD  R1, R1, baseReg
    const TargetInstrInfo &TII = *Subtarget.getInstrInfo();
    BuildMI(*MI.getParent(), II, DL,  TII.get(Vanilla::MOVI), Vanilla::R1).addImm(Offset);
    BuildMI(*MI.getParent(), II, DL,  TII.get(Vanilla::ADDU), Vanilla::R1).addReg(Vanilla::R1).addReg(baseReg);
  }
  else{
    //MOVI R1, (Offset & 0x7ff)
    //APPI R1, R1, (Offset >> 11)
    //ADDU R1, R1, baseReg
    const TargetInstrInfo &TII = *Subtarget.getInstrInfo();
    BuildMI(*MI.getParent(), II, DL,  TII.get(Vanilla::MOVI), Vanilla::R1).addImm(Offset & 0x7ff);
    BuildMI(*MI.getParent(), II, DL,  TII.get(Vanilla::APPI), Vanilla::R1).addReg(Vanilla::R1).addImm(Offset >>11);
    BuildMI(*MI.getParent(), II, DL,  TII.get(Vanilla::ADDU), Vanilla::R1).addReg(Vanilla::R1).addReg(baseReg);
  }
  
  MI.getOperand(i).ChangeToRegister(Vanilla::R1, false);
  
}

unsigned VanillaRegisterInfo::getFrameRegister(const MachineFunction &MF) const {
  return Vanilla::R0;
}

