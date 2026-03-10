import pymem
import pymem.process
import struct

pm = pymem.Pymem("PlantsVsZombies.exe")

module = pymem.process.module_from_name(pm.process_handle, "PlantsVsZombies.exe")
base = module.lpBaseOfDll

instr = base + 0x94445

newmem = pm.allocate(1024)

jmp = newmem - instr - 5
pm.write_bytes(instr, b'\xE9' + struct.pack('<i', jmp), 5)

pm.write_bytes(instr + 5, b'\x90', 1)

code = b''

code += b'\xC7\x87\x78\x55\x00\x00' + struct.pack('<I',9999)

code += b'\x8B\x87\x78\x55\x00\x00'

jmp_back = (instr + 6) - (newmem + len(code) + 5)
code += b'\xE9' + struct.pack('<i', jmp_back)

pm.write_bytes(newmem, code, len(code))

print("Infinite Sun hook installed")
