import pymem
pm = pymem.Pymem("PlantsVsZombies.exe")
address = 0x1D25A578
change_value = 9999
pm.write_int(address,change_value)