package main

import (
        "bufio"
        "crypto/tls"
        "errors"
        "io"
        "log"
        "os"
        "strings"
        "time"

       smtp "github.com/emersion/go-smtp"
)

var (
    mailDir   = "/var/mailqueue"
)
// Backend implements SMTP authentication
type Backend struct {
        users map[string]string
}

func NewBackend(userFile string) *Backend {
        users := make(map[string]string)
        f, err := os.Open(userFile)
        if err != nil {
                log.Fatalf("failed to open users file: %v", err)
        }
        defer f.Close()

        scanner := bufio.NewScanner(f)
        for scanner.Scan() {
                line := strings.TrimSpace(scanner.Text())
                if line == "" || strings.HasPrefix(line, "#") {
                        continue
                }
                parts := strings.SplitN(line, ":", 2)
                if len(parts) != 2 {
                        continue
                }
                users[parts[0]] = parts[1]
        }
        return &Backend{users: users}
}

func (bkd *Backend) Login(state *smtp.ConnectionState, username, password string) (smtp.Session, error) {
        if pass, ok := bkd.users[username]; ok && pass == password {
                return &Session{}, nil
        }
        return nil, errors.New("invalid username or password")
}

func (bkd *Backend) AnonymousLogin(state *smtp.ConnectionState) (smtp.Session, error) {
        return nil, smtp.ErrAuthRequired
}

// Session handles the mail transaction
type Session struct {
    from string
    to   string
}

func (s *Session) Mail(from string, opts smtp.MailOptions) error {
    s.from = strings.Trim(from, " <>")
    log.Println("MAIL FROM (cleaned):", s.from)
    return nil
}

func (s *Session) Rcpt(to string) error {
    s.to = strings.Trim(to, " <>")
    log.Println("RCPT TO (cleaned):", s.to)
    return nil
}

func (s *Session) Data(r io.Reader) error {
    body, err := io.ReadAll(r)
    if err != nil {
        return err
    }

    cleanFrom := strings.Trim(s.from, " <>")
    cleanTo := strings.Trim(s.to, " <>")




  full := string(body)



    filename := fmt.Sprintf("mail-%d.eml", time.Now().UnixNano())
    filepath := fmt.Sprintf("%s/%s", mailDir, filename)

    log.Printf("DEBUG: Saving mail with From: %s To: %s", cleanFrom, cleanTo)

    err = os.WriteFile(filepath, []byte(full), 0644)
    if err != nil {
        return err
    }

    log.Println("📩 Saved email to:", filepath)
    return nil
}

func (s *Session) Reset() {}
func (s *Session) Logout() error {
        return nil
}

func main() {
        be := NewBackend("users.txt")

s := smtp.NewServer(be)
s.Addr = ":465"

// Read domain from file
domainData, err := os.ReadFile("/opt/go-mta/domain.txt")
if err != nil {
    log.Fatalf("failed to read domain file: %v", err)
}
domain := strings.TrimSpace(string(domainData))
s.Domain = domain

s.AuthDisabled = false
s.AllowInsecureAuth = false



        // Load cert for implicit TLS
        cert, err := tls.LoadX509KeyPair(
    "/etc/letsencrypt/live/" + domain + "/fullchain.pem",
    "/etc/letsencrypt/live/" + domain + "/privkey.pem",
)


        if err != nil {
                log.Fatalf("failed to load SSL cert: %v", err)
        }

        tlsConfig := &tls.Config{
                Certificates: []tls.Certificate{cert},
        }
        s.TLSConfig = tlsConfig

        ln, err := tls.Listen("tcp", s.Addr, tlsConfig)
        if err != nil {
                log.Fatalf("failed to listen on %s: %v", s.Addr, err)
        }

        log.Printf("Starting SMTPS server on %s", s.Addr)
        if err := s.Serve(ln); err != nil {
                log.Fatal(err)
        }
}
