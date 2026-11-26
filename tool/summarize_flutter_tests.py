"""Print bounded failure details while preserving the full JSON test artifact."""
import collections
import json
import sys


def summarize(lines):
    names = {}
    errors = collections.Counter()
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            print(line.rstrip()[:2000])
            continue
        kind = event.get('type')
        if kind == 'testStart':
            names[event['test']['id']] = event['test']['name']
        elif kind == 'error':
            test_id = event.get('testID')
            errors[test_id] += 1
            if errors[test_id] <= 2:
                print(f"FAILED: {names.get(test_id, test_id)}")
                print(str(event.get('error', ''))[:6000])
                print(str(event.get('stackTrace', ''))[:2000])
        elif kind == 'done':
            print(f"Flutter tests success: {event.get('success')}")
    for test_id, count in errors.items():
        print(f"{names.get(test_id, test_id)}: {count} error event(s)")


if __name__ == '__main__':
    with open(sys.argv[1], encoding='utf-8') as source:
        summarize(source)
