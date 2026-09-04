import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';

export function activate(context: vscode.ExtensionContext) {
    console.log('✅ Python Script Runner activated!');

    const disposable = vscode.commands.registerCommand('pythonrunner.runPythonScript', async (resource: vscode.Uri) => {
        if (resource) {
            const scriptPath = resource.fsPath;
            const scriptDir = path.dirname(scriptPath);
            const scriptName = path.basename(scriptPath);

            try {
                // Check if it's a Python file
                if (!scriptPath.endsWith('.py')) {
                    vscode.window.showErrorMessage('Please select a Python (.py) file');
                    return;
                }

                // Run the script
                await vscode.window.withProgress({
                    location: vscode.ProgressLocation.Notification,
                    title: `Running ${scriptName}...`,
                    cancellable: true
                }, async (progress, token) => {
                    token.onCancellationRequested(() => {
                        vscode.window.showInformationMessage('Python script execution cancelled');
                    });

                    // Create terminal
                    const terminal = vscode.window.createTerminal({
                        name: `Run ${scriptName}`,
                        cwd: scriptDir
                    });

                    // Show the terminal
                    terminal.show();

                    // Determine which Python command to use
                    let pythonCmd = 'python3';
                    
                    // Try to detect Python interpreter from VS Code Python extension
                    try {
                        const pythonExtension = vscode.extensions.getExtension('ms-python.python');
                        if (pythonExtension) {
                            const pythonPath = await pythonExtension.exports.settings.getExecutionDetails(scriptPath).execCommand;
                            if (pythonPath && pythonPath.length > 0) {
                                pythonCmd = pythonPath.join(' ');
                            }
                        }
                    } catch (e) {
                        // Fallback to checking common Python commands
                        try {
                            // Check if python3 exists
                            const terminal2 = vscode.window.createTerminal('Python Check');
                            terminal2.sendText('which python3 && echo "PYTHON3_FOUND" || echo "PYTHON3_NOT_FOUND"');
                            // For simplicity, we'll just use python3 and let the terminal handle it
                        } catch (e2) {
                            // Keep default
                        }
                    }

                    // Check for virtual environment in common locations
                    const venvPaths = [
                        path.join(scriptDir, 'venv', 'bin', 'python'),
                        path.join(scriptDir, '.venv', 'bin', 'python'),
                        path.join(scriptDir, 'env', 'bin', 'python'),
                        path.join(scriptDir, '..', 'venv', 'bin', 'python'),
                        path.join(scriptDir, '..', '.venv', 'bin', 'python')
                    ];

                    let venvFound = false;
                    for (const venvPath of venvPaths) {
                        try {
                            if (fs.existsSync(venvPath)) {
                                pythonCmd = `"${venvPath}"`;
                                venvFound = true;
                                vscode.window.showInformationMessage(`Using virtual env: ${path.basename(path.dirname(path.dirname(venvPath)))}`);
                                break;
                            }
                        } catch (e) {}
                    }

                    // Run the Python script
                    terminal.sendText(`cd "${scriptDir}" && ${pythonCmd} "${scriptName}"`);

                    // Wait a bit for output
                    await new Promise(resolve => setTimeout(resolve, 1000));
                });

            } catch (error: any) {
                vscode.window.showErrorMessage(`Failed to run Python script: ${error.message}`);
                console.error('Python runner error:', error);
            }
        } else {
            vscode.window.showWarningMessage('Please select a Python script file (.py) to run');
        }
    });

    context.subscriptions.push(disposable);
}

export function deactivate() {}
