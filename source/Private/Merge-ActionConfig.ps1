function Merge-ActionConfig {
    <#
    .SYNOPSIS
        Merges a layer of configuration onto a base using scalar-override
        and array-append semantics.

    .DESCRIPTION
        Rules:
        - Scalar values: child replaces parent (last writer wins).
        - Array values: child appends to parent.
        - Hashtable values: shallow merge (child keys overwrite parent keys).
        - Key! suffix: forces array replacement instead of append.

        The base hashtable defines the canonical types -- if a key has an
        array value in the base, any child value for that key is appended.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Base,

        [Parameter(Mandatory)]
        [AllowNull()]
        [hashtable]$Layer
    )

    $result = $Base.Clone()

    if ($null -eq $Layer) { return $result }

    foreach ($key in $Layer.Keys) {
        $value = $Layer[$key]

        # Escape hatch: key! suffix forces array replacement
        if ($key.EndsWith('!')) {
            $realKey = $key.TrimEnd('!')
            $result[$realKey] = @($value)
            continue
        }

        # If base has an array for this key, append
        if ($result.ContainsKey($key) -and $result[$key] -is [array]) {
            $result[$key] = @($result[$key]) + @($value)
            continue
        }

        # If both sides are hashtables, shallow merge
        if ($result.ContainsKey($key) -and
            $result[$key] -is [hashtable] -and
            $value -is [hashtable]) {
            $merged = $result[$key].Clone()
            foreach ($subKey in $value.Keys) {
                $merged[$subKey] = $value[$subKey]
            }
            $result[$key] = $merged
            continue
        }

        # Scalar override (or new key)
        $result[$key] = $value
    }

    return $result
}
