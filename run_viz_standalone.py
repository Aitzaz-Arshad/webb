import sys
import json
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from visualize_planning import visualize_from_server_response
import os

if len(sys.argv) < 2:
    print("Error: No data file provided")
    sys.exit(1)

temp_file = sys.argv[1]

try:
    with open(temp_file, 'r') as f:
        data = json.load(f)
    
    print("=" * 70)
    print("VISUALIZATION OPTIONS:")
    print("=" * 70)
    print("  1 = Show A* path only")
    print("  2 = Show smooth path only")
    print("  3 = Show both paths (DEFAULT)")
    print("  4 = Show obstacle inflation comparison")
    print("=" * 70)
    
    flag_input = input("Enter flag number (1-4) [default=3]: ").strip()
    
    if flag_input == '':
        flag = 3
    else:
        try:
            flag = int(flag_input)
            if flag not in [1, 2, 3, 4]:
                print(f"Invalid flag {flag}, using 3")
                flag = 3
        except ValueError:
            print(f"Invalid input '{flag_input}', using 3")
            flag = 3
    
    print(f"\nUsing flag: {flag}")
    print("=" * 70)
    print("Creating visualization...")
    
    viz = visualize_from_server_response(
        response_data=data['response_data'],
        obstacles=data['inflated_obstacles'],
        boundary=data['boundary'],
        start=tuple(data['start']),
        goal=tuple(data['goal']),
        flag=flag,
        show_inflation=(flag == 4),
        original_obstacles=data.get('original_obstacles') if flag == 4 else None
    )
    
    print("[OK] Visualization created!")
    print("[*] Displaying plot window...")
    print("[!] CLOSE THE PLOT WINDOW WHEN DONE")
    print("=" * 70 + "\n")
    
    viz.show()
    
    print("\n[OK] Visualization window closed!")
    
except KeyboardInterrupt:
    print("\n[!] Interrupted by user")
except Exception as e:
    print(f"[ERROR] {e}")
    import traceback
    traceback.print_exc()
finally:
    try:
        if os.path.exists(temp_file):
            os.remove(temp_file)
            print(f"[*] Cleaned up {temp_file}")
    except Exception as e:
        print(f"[!] Could not clean up temp file: {e}")
    
    input("\nPress Enter to close this window...")
