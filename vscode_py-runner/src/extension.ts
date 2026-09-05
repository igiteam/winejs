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
                    let venvPath = null;
                    
                    // Check for virtual environment in common locations
                    const venvPaths = [
                        path.join(scriptDir, 'venv'),
                        path.join(scriptDir, '.venv'),
                        path.join(scriptDir, 'env'),
                        path.join(scriptDir, '..', 'venv'),
                        path.join(scriptDir, '..', '.venv')
                    ];

                    for (const venvDir of venvPaths) {
                        const pythonExe = path.join(venvDir, 'bin', 'python');
                        if (fs.existsSync(pythonExe)) {
                            pythonCmd = `"${pythonExe}"`;
                            venvPath = venvDir;
                            terminal.sendText(`echo "✅ Using virtual env: ${path.basename(venvDir)}"`);
                            break;
                        }
                    }

                    // Check for requirements.txt and install if found
                    const requirementsPath = path.join(scriptDir, 'requirements.txt');
                    const parentRequirementsPath = path.join(scriptDir, '..', 'requirements.txt');
                    
                    let hasRequirements = false;
                    let reqPath = null;
                    
                    if (fs.existsSync(requirementsPath)) {
                        hasRequirements = true;
                        reqPath = requirementsPath;
                    } else if (fs.existsSync(parentRequirementsPath)) {
                        hasRequirements = true;
                        reqPath = parentRequirementsPath;
                    }

                    if (hasRequirements && reqPath) {
                        terminal.sendText(`echo "📦 Found requirements.txt - installing dependencies..."`);
                        
                        // If no virtual environment exists, create one
                        if (!venvPath) {
                            const venvDir = path.join(scriptDir, '.venv');
                            terminal.sendText(`echo "🔧 Creating virtual environment in .venv..."`);
                            terminal.sendText(`python3 -m venv "${venvDir}"`);
                            terminal.sendText(`echo "✅ Virtual environment created!"`);
                            
                            // Use the new venv's pip
                            const venvPython = path.join(venvDir, 'bin', 'python');
                            terminal.sendText(`${venvPython} -m pip install --upgrade pip`);
                            terminal.sendText(`${venvPython} -m pip install -r "${reqPath}"`);
                            terminal.sendText(`echo "✅ Dependencies installed in virtual environment!"`);
                            
                            // Update pythonCmd to use the venv
                            pythonCmd = `"${venvPython}"`;
                        } else {
                            // Virtual environment exists, use it
                            terminal.sendText(`${pythonCmd} -m pip install --upgrade pip`);
                            terminal.sendText(`${pythonCmd} -m pip install -r "${reqPath}"`);
                            terminal.sendText(`echo "✅ Dependencies installed successfully!"`);
                        }
                    }

                    // Run the Python script
                    terminal.sendText(`echo "🚀 Running ${scriptName}..."`);
                    terminal.sendText(`cd "${scriptDir}" && ${pythonCmd} "${scriptName}"`);
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
