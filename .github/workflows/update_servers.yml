name: Update VPN Servers

on:
  schedule:
    - cron: '0 */6 * * *'   # كل 6 ساعات (بدل يومياً)
  workflow_dispatch:

jobs:
  update:
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install requests supabase

      - name: Fetch and upload servers
        env:
          SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_SERVICE_KEY }}
        run: python .github/scripts/update_servers.py
