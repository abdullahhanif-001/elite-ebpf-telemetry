package service

import (
	"encoding/json"
	"path/filepath"
	"testing"
	"time"

	"github.com/alibaba/kubeskoop/pkg/controller/db"
)

func TestDB(t *testing.T) {
	dir := t.TempDir()
	if err := db.InitializeDB(&db.Config{
		Type: "sqlite3",
		Addr: filepath.Join(dir, "test.sqlite3"),
	}); err != nil {
		t.Fatalf("init db: %v", err)
	}

	startTime := time.Now().Format("2006-01-02 15:04:05")
	task := DiagnoseTaskResult{TaskConfig: "", StartTime: startTime, Status: "running"}
	id, err := saveTask(&task)
	if err != nil {
		t.Fatalf("failed save task, err:%v", err)
	}
	task.TaskID = id

	task.Status = "success"
	updateTask(&task)

	tasks, err := listTasks()
	if err != nil {
		t.Fatalf("failed list task, err:%v", err)
	}
	for _, task := range tasks {
		data, _ := json.Marshal(task)
		t.Logf("task: %s", string(data))
	}
}
