# Registra CPU y memoria del equipo cada segundo en un CSV, mientras corre la prueba.
# Alternativa a PerfMon + ServerAgent: en este equipo la librería nativa del ServerAgent
# (sigar-amd64-winnt.dll) se cae con EXCEPTION_ACCESS_VIOLATION al pedir cualquier métrica.
#
# Uso (en una terminal aparte, ANTES de lanzar JMeter):
#   powershell -ExecutionPolicy Bypass -File monitor_recursos.ps1 -Segundos 120 -Salida recursos_q10.csv
# Se detiene solo al cumplir los segundos, o antes con Ctrl+C.
#
# Columnas:
#   hora              hora de la muestra
#   cpu_total_pct     uso de CPU de todo el equipo (%)
#   memoria_usada_pct memoria física en uso de todo el equipo (%)
#   api_python_mb     memoria del proceso de la API (python)
#   jmeter_java_mb    memoria del proceso de JMeter (java)

param(
    [int]$Segundos = 600,
    [string]$Salida = 'recursos.csv'
)

"hora,cpu_total_pct,memoria_usada_pct,api_python_mb,jmeter_java_mb" | Out-File -Encoding utf8 $Salida
Write-Host "Registrando CPU y memoria en $Salida durante $Segundos s (Ctrl+C para detener)..."

for ($i = 0; $i -lt $Segundos; $i++) {
    $inicio = Get-Date
    $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
    $os = Get-CimInstance Win32_OperatingSystem
    $mem = [math]::Round(100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize), 1)
    $py = [math]::Round(((Get-Process python -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 1)
    $jv = [math]::Round(((Get-Process java -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 1)
    # Punto decimal siempre (en Windows en español la coma rompería las columnas del CSV)
    $linea = [string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0},{1},{2},{3},{4}", $inicio.ToString('HH:mm:ss'), $cpu, $mem, $py, $jv)
    $linea | Out-File -Encoding utf8 -Append $Salida
    Write-Host $linea
    $espera = 1000 - ((Get-Date) - $inicio).TotalMilliseconds
    if ($espera -gt 0) { Start-Sleep -Milliseconds $espera }
}
Write-Host "Listo: $Salida"
