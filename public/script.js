// Taken from w3schools
function sortTable(n, table) {
  let rows, i, x, y, shouldSwitch, switchcount = 0
  let switching = true
  let dirUp = true
  while (switching) {
    switching = false
    rows = table.rows
    for (i = 1; i < (rows.length - 1); i++) {
      shouldSwitch = false
      x = rows[i].getElementsByTagName("TD")[n]
      y = rows[i + 1].getElementsByTagName("TD")[n]
      if (dirUp == true) {
        if (x.innerHTML.toLowerCase() > y.innerHTML.toLowerCase()) {
          shouldSwitch = true
          break
        }
      } else if (dirUp == false) {
        if (x.innerHTML.toLowerCase() < y.innerHTML.toLowerCase()) {
          shouldSwitch = true
          break
        }
      }
    }
    if (shouldSwitch) {
      rows[i].parentNode.insertBefore(rows[i + 1], rows[i])
      switching = true
      switchcount ++
    } else {
      if (switchcount == 0 && dirUp == true) {
        dirUp = false
        switching = true
      }
    }
  }
}