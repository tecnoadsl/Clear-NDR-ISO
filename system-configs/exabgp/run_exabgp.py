#!/usr/bin/env python3
import sys
sys.argv = ['exabgp', 'server'] + sys.argv[1:]
from exabgp.application.main import main
main()
